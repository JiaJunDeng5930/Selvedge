#![doc = include_str!("../README.md")]

use std::collections::{HashMap, VecDeque};
use std::sync::Arc;

use selvedge_api::{ApiExecutorConfig, spawn_model_call_tokio_task};
use selvedge_command_model::{
    ApiOutputEnvelope, CoreOutputEnvelope, CoreOutputMessage, DebugRawEvent, DetachReason,
    DomainEvent, DomainEventPublishRequest, EventClientReservationResult, EventControlMessage,
    EventIngress, EventIngressSender, FactoryEffectId, FactoryFailureKind, FactoryOutput,
    FactoryOutputEnvelope, FactoryScanOutput, FactoryTaskFailure, ForkTaskError, ForkTaskOutcome,
    ForkTaskResponder, RawEvent, ReserveClientSession, RouterAttachAdmissionResult, RouterCommand,
    RouterCommandEnvelope, RouterIngressMessage, RouterIngressSender, RouterIngressWeakSender,
    TaskCommandError, TaskRuntimeCommand, TaskRuntimeControl, TaskRuntimeExitNotice,
    TaskRuntimeSender, ToolExecutionRequest, ToolExecutionResult, validate_router_command,
};
use selvedge_core::TaskRuntimeSpawnDeps;
use selvedge_db::DbPool;
use selvedge_domain_model::TaskId;
use selvedge_task_runtime_factory::{
    FactoryCommand, FactoryEffectArgs, FactoryRuntimeInventory, run_factory_effect,
};
use tokio::task::JoinHandle;

pub struct RouterStartArgs {
    pub db: DbPool,
    pub events_tx: EventIngressSender,
    pub api_config: ApiExecutorConfig,
    pub tool_executor: Arc<dyn ToolExecutionSpawner>,
    pub core_spawn_deps: TaskRuntimeSpawnDeps,
}

pub trait ToolExecutionSpawner: Send + Sync {
    fn spawn_tool_execution(
        &self,
        request: ToolExecutionRequest,
        router_tx: RouterIngressWeakSender,
    ) -> Result<JoinHandle<()>, ToolExecutionSpawnError>;
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ToolExecutionSpawnError {
    TokioSpawnFailed,
    ToolExecutorUnavailable,
}

pub struct RouterHandle {
    pub ingress_tx: RouterIngressSender,
    pub join_handle: JoinHandle<RouterExitStatus>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RouterExitStatus {
    Stopped,
    EventsMailboxClosed,
    RouterMailboxClosed,
    FatalError(String),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SpawnRouterError {
    TokioSpawnFailed,
}

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

struct PendingRuntimeEffect {
    task_id: Option<TaskId>,
    fork_responder: Option<ForkTaskResponder>,
}

#[derive(Clone, Debug)]
struct RuntimeRegistryEntry {
    sender: TaskRuntimeSender,
    control: TaskRuntimeControl,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum RegisterRuntimeOutcome {
    Started,
    Failed,
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
                    self.shutdown().await;
                    return RouterExitStatus::Stopped;
                }
            };

            if let Err(status) = result {
                self.shutdown().await;
                return status;
            }
        }

        self.shutdown().await;
        RouterExitStatus::RouterMailboxClosed
    }

    async fn handle_command(
        &mut self,
        envelope: RouterCommandEnvelope,
    ) -> Result<(), RouterExitStatus> {
        if validate_router_command(&envelope).is_err() {
            settle_router_command(envelope.command, TaskCommandError::InvalidCommand);
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
                responder,
            } => {
                self.route_task_local_command(
                    task_id,
                    TaskRuntimeCommand::UserInput {
                        message_text,
                        responder,
                    },
                    true,
                )
                .await
            }
            RouterCommand::ArchiveTask { task_id, responder } => {
                self.route_task_local_command(
                    task_id,
                    TaskRuntimeCommand::Archive { responder },
                    true,
                )
                .await
            }
            RouterCommand::StopTaskRuntime { task_id } => self.stop_task_runtime(task_id).await,
            RouterCommand::EnsureTaskRuntime { task_id } => self.ensure_task_runtime(task_id).await,
            RouterCommand::EnsureMissingTaskRuntimes => self.ensure_missing_task_runtimes().await,
            RouterCommand::CreateChildTaskAndRuntime {
                parent_task_id,
                function_call_node_id,
                function_call_id,
                tool_name,
                child_prompt,
                responder,
            } => {
                self.create_child_task_and_runtime(
                    parent_task_id,
                    function_call_node_id,
                    function_call_id,
                    tool_name,
                    child_prompt,
                    responder,
                )
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
    ) -> Result<(), RouterExitStatus> {
        let (result_tx, result_rx) = tokio::sync::oneshot::channel();
        let cleanup_client_id = client_id.clone();
        let cleanup_client_command_id = client_command_id.clone();
        if self
            .events_tx
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
            let _ = admission_tx.send(RouterAttachAdmissionResult::EventsMailboxClosed);
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
            Err(_) => (RouterAttachAdmissionResult::EventsMailboxClosed, false),
        };

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
    ) -> Result<(), RouterExitStatus> {
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
    ) -> Result<(), RouterExitStatus> {
        let effect_id = self.next_effect_id();
        self.pending_effects.insert(
            effect_id.clone(),
            PendingRuntimeEffect {
                task_id: Some(task_id.clone()),
                fork_responder: None,
            },
        );
        self.pending_effects_by_task
            .insert(task_id.clone(), effect_id.clone());
        let command = FactoryCommand::EnsureTaskRuntime { task_id };
        self.run_factory_effect(effect_id, command).await
    }

    async fn ensure_missing_task_runtimes(&mut self) -> Result<(), RouterExitStatus> {
        let effect_id = self.next_effect_id();
        self.pending_effects.insert(
            effect_id.clone(),
            PendingRuntimeEffect {
                task_id: None,
                fork_responder: None,
            },
        );
        self.run_factory_effect(effect_id, FactoryCommand::EnsureMissingTaskRuntimes)
            .await
    }

    async fn create_child_task_and_runtime(
        &mut self,
        parent_task_id: TaskId,
        function_call_node_id: selvedge_domain_model::HistoryNodeId,
        function_call_id: selvedge_domain_model::FunctionCallId,
        tool_name: selvedge_domain_model::ToolName,
        child_prompt: String,
        responder: ForkTaskResponder,
    ) -> Result<(), RouterExitStatus> {
        let effect_id = self.next_effect_id();
        self.pending_effects.insert(
            effect_id.clone(),
            PendingRuntimeEffect {
                task_id: None,
                fork_responder: Some(responder),
            },
        );
        let command = FactoryCommand::CreateChildTaskAndRuntime {
            parent_task_id,
            function_call_node_id,
            function_call_id,
            tool_name,
            child_prompt,
        };
        self.run_factory_effect(effect_id, command).await
    }

    async fn run_factory_effect(
        &mut self,
        effect_id: FactoryEffectId,
        command: FactoryCommand,
    ) -> Result<(), RouterExitStatus> {
        let current_task_effect = match &command {
            FactoryCommand::EnsureTaskRuntime { task_id } => Some(task_id),
            FactoryCommand::EnsureMissingTaskRuntimes
            | FactoryCommand::CreateChildTaskAndRuntime { .. } => None,
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
        let pending_effect_id = effect_id.clone();
        let factory_args = FactoryEffectArgs {
            effect_id,
            command,
            db: self.db.clone(),
            router_tx: self.router_tx.clone(),
            core_spawn_deps: self.core_spawn_deps.clone(),
            runtime_inventory: inventory,
        };
        let envelope =
            match tokio::task::spawn_blocking(move || run_factory_effect(factory_args)).await {
                Ok(envelope) => envelope,
                Err(error) => {
                    let Some(mut pending) = self.pending_effects.remove(&pending_effect_id) else {
                        return Ok(());
                    };
                    if let Some(task_id) = &pending.task_id {
                        self.pending_effects_by_task.remove(task_id);
                        self.fail_deferred_commands(task_id, TaskCommandError::RuntimeUnavailable);
                    }
                    if let Some(responder) = pending.fork_responder.take() {
                        responder.settle(Err(ForkTaskError::RuntimeUnavailable));
                    }
                    return self
                        .publish_debug(None, format!("factory effect task failed: {error}"))
                        .await;
                }
            };
        self.apply_factory_output(envelope).await
    }

    async fn apply_factory_output(
        &mut self,
        envelope: FactoryOutputEnvelope,
    ) -> Result<(), RouterExitStatus> {
        let Some(mut pending) = self.pending_effects.remove(&envelope.effect_id) else {
            return self
                .publish_debug(None, "stale factory output discarded")
                .await;
        };
        let pending_task_id = pending.task_id.take();
        let fork_responder = pending.fork_responder.take();
        if let Some(task_id) = &pending_task_id {
            self.pending_effects_by_task.remove(task_id);
        }

        match envelope.output {
            FactoryOutput::RuntimeCreated(created) => {
                if let Some(responder) = fork_responder {
                    let child_task_id = created.task_id.clone();
                    if created.created_runtime_kind
                        != selvedge_command_model::CreatedRuntimeKind::ChildTaskRuntime
                    {
                        responder.settle(Err(ForkTaskError::RuntimeUnavailable));
                        return self
                            .publish_debug(
                                Some(child_task_id),
                                "factory runtime kind did not match fork effect",
                            )
                            .await;
                    }
                    return match self
                        .register_runtime(
                            created.task_id,
                            created.task_runtime_tx,
                            created.task_runtime_control,
                        )
                        .await
                    {
                        Ok(RegisterRuntimeOutcome::Started) => {
                            responder.settle(Ok(ForkTaskOutcome::RuntimeStarted {
                                task_id: child_task_id,
                            }));
                            Ok(())
                        }
                        Ok(RegisterRuntimeOutcome::Failed) => {
                            responder.settle(Err(
                                ForkTaskError::RuntimeStartFailedAfterChildCreated {
                                    task_id: child_task_id,
                                },
                            ));
                            Ok(())
                        }
                        Err(status) => {
                            responder.settle(Err(
                                ForkTaskError::RuntimeStartFailedAfterChildCreated {
                                    task_id: child_task_id,
                                },
                            ));
                            Err(status)
                        }
                    };
                }
                if pending_task_id
                    .as_ref()
                    .is_some_and(|task_id| task_id != &created.task_id)
                {
                    if let Some(task_id) = pending_task_id {
                        self.fail_deferred_commands(&task_id, TaskCommandError::RuntimeUnavailable);
                    }
                    return self
                        .publish_debug(
                            Some(created.task_id),
                            "factory runtime task id did not match pending effect",
                        )
                        .await;
                }
                self.register_runtime(
                    created.task_id,
                    created.task_runtime_tx,
                    created.task_runtime_control,
                )
                .await
                .map(|_| ())
            }
            FactoryOutput::ScanFinished(scan) => {
                if let Some(responder) = fork_responder {
                    responder.settle(Err(ForkTaskError::RuntimeUnavailable));
                }
                if let Some(task_id) = pending_task_id {
                    self.fail_deferred_commands(&task_id, TaskCommandError::RuntimeUnavailable);
                    return self
                        .publish_debug(
                            Some(task_id),
                            "factory scan output did not match pending task effect",
                        )
                        .await;
                }
                self.apply_scan_output(scan).await
            }
            FactoryOutput::Failed(failure) => {
                if let Some(responder) = fork_responder {
                    responder.settle(Err(fork_task_factory_error(
                        &failure.kind,
                        failure.task_id.as_ref(),
                    )));
                }
                if let Some(task_id) = pending_task_id {
                    if failure.task_id.as_ref() != Some(&task_id) {
                        self.fail_deferred_commands(&task_id, TaskCommandError::RuntimeUnavailable);
                        return self
                            .publish_debug(
                                Some(task_id),
                                "factory failure task id did not match pending effect",
                            )
                            .await;
                    }
                    self.fail_deferred_commands(
                        &task_id,
                        task_command_factory_error(&failure.kind),
                    );
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
    ) -> Result<RegisterRuntimeOutcome, RouterExitStatus> {
        if self.task_runtime_registry.contains_key(&task_id) {
            self.fail_deferred_commands(&task_id, TaskCommandError::RuntimeUnavailable);
            self.publish_debug(
                Some(task_id),
                "factory runtime would replace a live task runtime",
            )
            .await?;
            return Ok(RegisterRuntimeOutcome::Failed);
        }
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
            .any(|command| matches!(command, TaskRuntimeCommand::Archive { .. }))
        {
            while let Some(command) = deferred.pop_front() {
                if let Err(error) = sender.send(command).await {
                    self.task_runtime_registry.remove(&task_id);
                    settle_task_runtime_command(error.0, TaskCommandError::RuntimeUnavailable);
                    settle_task_runtime_commands(deferred, TaskCommandError::RuntimeUnavailable);
                    self.publish_debug(Some(task_id), "deferred task command delivery failed")
                        .await?;
                    return Ok(RegisterRuntimeOutcome::Failed);
                }
            }
            return Ok(RegisterRuntimeOutcome::Started);
        }

        if sender.send(TaskRuntimeCommand::Start).await.is_err() {
            self.task_runtime_registry.remove(&task_id);
            settle_task_runtime_commands(deferred, TaskCommandError::RuntimeUnavailable);
            self.publish_debug(Some(task_id), "task runtime start failed")
                .await?;
            return Ok(RegisterRuntimeOutcome::Failed);
        }

        while let Some(command) = deferred.pop_front() {
            if let Err(error) = sender.send(command).await {
                self.task_runtime_registry.remove(&task_id);
                settle_task_runtime_command(error.0, TaskCommandError::RuntimeUnavailable);
                settle_task_runtime_commands(deferred, TaskCommandError::RuntimeUnavailable);
                self.publish_debug(Some(task_id), "deferred task command delivery failed")
                    .await?;
                return Ok(RegisterRuntimeOutcome::Failed);
            }
        }
        Ok(RegisterRuntimeOutcome::Started)
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
        if let Some(effect_id) = self.pending_effects_by_task.remove(&task_id) {
            self.pending_effects.remove(&effect_id);
            self.fail_deferred_commands(&task_id, TaskCommandError::RuntimeUnavailable);
            return self
                .publish_debug(Some(task_id), "pending task runtime creation cancelled")
                .await;
        }
        self.publish_debug(Some(task_id), "task runtime is not live")
            .await
    }

    async fn shutdown(&mut self) {
        self.ingress_rx.close();
        let deferred = std::mem::take(&mut self.deferred_commands);
        for commands in deferred.into_values() {
            settle_task_runtime_commands(commands, TaskCommandError::RuntimeUnavailable);
        }
        self.pending_effects.clear();
        self.pending_effects_by_task.clear();
        self.stop_runtimes().await;
        while let Some(ingress) = self.ingress_rx.recv().await {
            settle_router_ingress(ingress, TaskCommandError::RuntimeUnavailable);
        }
    }

    fn fail_deferred_commands(&mut self, task_id: &TaskId, error: TaskCommandError) {
        if let Some(commands) = self.deferred_commands.remove(task_id) {
            settle_task_runtime_commands(commands, error);
        }
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
    ) -> Result<(), RouterExitStatus> {
        self.publish_debug(Some(failure.task_id), failure.message)
            .await
    }

    async fn send_event(&mut self, event: EventIngress) -> Result<(), RouterExitStatus> {
        self.events_tx
            .send(event)
            .await
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

fn settle_router_ingress(ingress: RouterIngressMessage, error: TaskCommandError) {
    if let RouterIngressMessage::Command(envelope) = ingress {
        settle_router_command(envelope.command, error);
    }
}

fn settle_router_command(command: RouterCommand, error: TaskCommandError) {
    match command {
        RouterCommand::SendUserInput { responder, .. } => responder.settle(Err(error)),
        RouterCommand::ArchiveTask { responder, .. } => responder.settle(Err(error)),
        RouterCommand::CreateChildTaskAndRuntime { responder, .. } => {
            let error = if error == TaskCommandError::InvalidCommand {
                ForkTaskError::InvalidCommand
            } else {
                ForkTaskError::RuntimeUnavailable
            };
            responder.settle(Err(error));
        }
        RouterCommand::AttachClient { .. }
        | RouterCommand::DetachClient { .. }
        | RouterCommand::UpdateSubscription { .. }
        | RouterCommand::StopTaskRuntime { .. }
        | RouterCommand::EnsureTaskRuntime { .. }
        | RouterCommand::EnsureMissingTaskRuntimes => {}
    }
}

fn settle_task_runtime_commands(
    mut commands: VecDeque<TaskRuntimeCommand>,
    error: TaskCommandError,
) {
    while let Some(command) = commands.pop_front() {
        settle_task_runtime_command(command, error);
    }
}

fn settle_task_runtime_command(command: TaskRuntimeCommand, error: TaskCommandError) {
    match command {
        TaskRuntimeCommand::UserInput { responder, .. } => responder.settle(Err(error)),
        TaskRuntimeCommand::Archive { responder } => responder.settle(Err(error)),
        TaskRuntimeCommand::Start
        | TaskRuntimeCommand::ApiModelReply(_)
        | TaskRuntimeCommand::ToolResult(_) => {}
    }
}

fn task_command_factory_error(kind: &FactoryFailureKind) -> TaskCommandError {
    match kind {
        FactoryFailureKind::TaskMissing | FactoryFailureKind::ParentTaskMissing => {
            TaskCommandError::TaskMissing
        }
        FactoryFailureKind::TaskArchived | FactoryFailureKind::ParentTaskArchived => {
            TaskCommandError::TaskArchived
        }
        FactoryFailureKind::DbReadFailed
        | FactoryFailureKind::DbWriteFailed
        | FactoryFailureKind::StaleToolCall => TaskCommandError::PersistenceFailed,
        FactoryFailureKind::RuntimeInventoryUnavailable
        | FactoryFailureKind::RuntimeAlreadyLive
        | FactoryFailureKind::RuntimeCreationPending
        | FactoryFailureKind::CoreSpawnFailed => TaskCommandError::RuntimeUnavailable,
    }
}

fn fork_task_factory_error(kind: &FactoryFailureKind, task_id: Option<&TaskId>) -> ForkTaskError {
    match kind {
        FactoryFailureKind::ParentTaskMissing | FactoryFailureKind::TaskMissing => {
            ForkTaskError::ParentTaskMissing
        }
        FactoryFailureKind::ParentTaskArchived | FactoryFailureKind::TaskArchived => {
            ForkTaskError::ParentTaskArchived
        }
        FactoryFailureKind::StaleToolCall => ForkTaskError::StaleToolCall,
        FactoryFailureKind::DbReadFailed | FactoryFailureKind::DbWriteFailed => {
            ForkTaskError::PersistenceFailed
        }
        FactoryFailureKind::CoreSpawnFailed => {
            task_id.map_or(ForkTaskError::RuntimeUnavailable, |task_id| {
                ForkTaskError::RuntimeStartFailedAfterChildCreated {
                    task_id: task_id.clone(),
                }
            })
        }
        FactoryFailureKind::RuntimeInventoryUnavailable
        | FactoryFailureKind::RuntimeAlreadyLive
        | FactoryFailureKind::RuntimeCreationPending => ForkTaskError::RuntimeUnavailable,
    }
}
