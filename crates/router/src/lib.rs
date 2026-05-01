#![doc = include_str!("../README.md")]

use std::collections::{HashMap, VecDeque};
use std::sync::Arc;

use selvedge_api::{ApiExecutorConfig, ModelProviderRegistry, spawn_model_call_tokio_task};
use selvedge_command_model::{
    ApiOutputEnvelope, CoreOutputEnvelope, CoreOutputMessage, DebugRawEvent, DetachReason,
    DomainEvent, DomainEventPublishRequest, EventControlMessage, EventIngress, EventIngressSender,
    FactoryEffectId, FactoryOutput, FactoryOutputEnvelope, FactoryScanOutput, FactoryTaskFailure,
    RawEvent, RouterCommand, RouterCommandEnvelope, RouterIngressMessage, RouterIngressSender,
    TaskRuntimeCommand, TaskRuntimeExitNotice, TaskRuntimeInstanceId, TaskRuntimeSender,
    ToolExecutionRequest, ToolExecutionResult, validate_router_command,
};
use selvedge_core::TaskRuntimeSpawnDeps;
use selvedge_db::DbPool;
use selvedge_domain_model::TaskId;
use selvedge_task_runtime_factory::{
    CreateChildTaskAndRuntimeCommand, EnsureMissingTaskRuntimesCommand, EnsureTaskRuntimeCommand,
    FactoryCommand, FactoryEffectArgs, FactoryRuntimeInventory, run_factory_effect,
};
use tokio::task::JoinHandle;

pub struct RouterStartArgs {
    pub db: DbPool,
    pub events_tx: EventIngressSender,
    pub api_provider_registry: Arc<dyn ModelProviderRegistry>,
    pub api_config: ApiExecutorConfig,
    pub tool_executor: Arc<dyn ToolExecutionSpawner>,
    pub core_spawn_deps: TaskRuntimeSpawnDeps,
    pub router_mailbox_capacity: usize,
}

pub trait ToolExecutionSpawner: Send + Sync {
    fn spawn_tool_execution(
        &self,
        request: ToolExecutionRequest,
        router_tx: RouterIngressSender,
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
    InvalidMailboxCapacity,
    TokioSpawnFailed,
}

pub fn spawn_router(args: RouterStartArgs) -> Result<RouterHandle, SpawnRouterError> {
    if args.router_mailbox_capacity == 0 {
        return Err(SpawnRouterError::InvalidMailboxCapacity);
    }

    let (ingress_tx, ingress_rx) = tokio::sync::mpsc::channel(args.router_mailbox_capacity);
    let actor = RouterActor {
        db: args.db,
        events_tx: args.events_tx,
        api_provider_registry: args.api_provider_registry,
        api_config: args.api_config,
        tool_executor: args.tool_executor,
        core_spawn_deps: args.core_spawn_deps,
        router_tx: ingress_tx.clone(),
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
    api_provider_registry: Arc<dyn ModelProviderRegistry>,
    api_config: ApiExecutorConfig,
    tool_executor: Arc<dyn ToolExecutionSpawner>,
    core_spawn_deps: TaskRuntimeSpawnDeps,
    router_tx: RouterIngressSender,
    ingress_rx: tokio::sync::mpsc::Receiver<RouterIngressMessage>,
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
    task_runtime_instance_id: TaskRuntimeInstanceId,
    sender: TaskRuntimeSender,
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
                outbound,
                subscription,
            } => {
                self.send_event(EventIngress::Control(
                    EventControlMessage::BeginClientHydration(
                        selvedge_command_model::BeginClientHydration {
                            client_id,
                            client_command_id,
                            outbound,
                            subscription,
                        },
                    ),
                ))
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
        match envelope.message {
            CoreOutputMessage::RequestModelCall(request) => {
                let _join_handle = spawn_model_call_tokio_task(
                    request,
                    self.router_tx.clone(),
                    self.api_provider_registry.clone(),
                    self.api_config.clone(),
                );
                Ok(())
            }
            CoreOutputMessage::RequestToolExecution(request) => {
                match self
                    .tool_executor
                    .spawn_tool_execution(request, self.router_tx.clone())
                {
                    Ok(_join_handle) => Ok(()),
                    Err(_) => {
                        self.publish_debug(
                            Some(envelope.task_id),
                            "tool execution task spawn failed",
                        )
                        .await
                    }
                }
            }
            CoreOutputMessage::PublishDomainEvent(request) => {
                self.publish_domain_event(request).await
            }
            CoreOutputMessage::RuntimeReady => {
                self.publish_domain_event(DomainEventPublishRequest {
                    task_id: envelope.task_id,
                    event: DomainEvent::TaskRuntimeReady,
                })
                .await
            }
        }
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
            .is_some_and(|entry| entry.task_runtime_instance_id == notice.task_runtime_instance_id);
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
                    created.task_runtime_instance_id,
                    created.task_runtime_tx,
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
                created.task_runtime_instance_id,
                created.task_runtime_tx,
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
        task_runtime_instance_id: TaskRuntimeInstanceId,
        sender: TaskRuntimeSender,
    ) -> Result<(), RouterExitStatus> {
        self.task_runtime_registry.insert(
            task_id.clone(),
            RuntimeRegistryEntry {
                task_runtime_instance_id,
                sender: sender.clone(),
            },
        );
        let mut deferred = self.deferred_commands.remove(&task_id).unwrap_or_default();
        if deferred
            .iter()
            .any(|command| matches!(command, TaskRuntimeCommand::Archive))
        {
            while let Some(command) = deferred.pop_front() {
                if sender.send(command).await.is_err() {
                    self.task_runtime_registry.remove(&task_id);
                    return self
                        .publish_debug(Some(task_id), "deferred task command delivery failed")
                        .await;
                }
            }
            return Ok(());
        }

        if sender.send(TaskRuntimeCommand::Start).await.is_err() {
            self.task_runtime_registry.remove(&task_id);
            return self
                .publish_debug(Some(task_id), "task runtime start failed")
                .await;
        }

        while let Some(command) = deferred.pop_front() {
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
        if let Some(entry) = self.task_runtime_registry.remove(&task_id) {
            if entry.sender.send(TaskRuntimeCommand::Stop).await.is_err() {
                return self
                    .publish_debug(Some(task_id), "task runtime mailbox closed")
                    .await;
            }
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
        let senders = self
            .task_runtime_registry
            .drain()
            .map(|(_, entry)| entry.sender)
            .collect::<Vec<_>>();
        for sender in senders {
            let _ = sender.send(TaskRuntimeCommand::Stop).await;
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
